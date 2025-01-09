// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Contract to manage DID updates

// *******************************************************************************************
//
// WARNING: DO NOT USE THIS WITHOUT UNDERSTANDING ITS LIMITATIONS
//
// ALL KINDS OF THINGS YOU WOULD NORMALLY ASSUME ABOUT DID DIRECTORY UPDATES DO NOT APPLY HERE
//
// *******************************************************************************************

// https://web.plc.directory/spec/v0.1/did-plc
// https://ipld.io/specs/codecs/dag-cbor/spec/

import {console} from "forge-std/console.sol";

import {DidVerifier} from "./DidVerifier.sol";

contract MightHaveDonePLCDirectory is DidVerifier {
    event LogRegisterUpdate(bytes32 didGenesisHash, bytes32 parentHash, bytes32 newHash);

    // We will keep an update record for every item including the genesis operation
    struct UpdateOp {
        bytes32 parentHash;
        uint128 countChildren;
        uint128 recordedTimestamp;
        address verificationMethod;
    }

    struct Did {
        bytes didBytes;
        mapping(bytes32 => UpdateOp) updates;
        bytes32 uncontroversialTip; // The tip of the chain, or 0x0 if the chain has forked
    }

    struct ApprovalRule {
        bytes32 fromUpdateOp;
        uint256 untilTS;
    }

    enum UpdateEntry {
        oneOfManyPossibleCids,
        createdAt,
        numRotationKeys,
        rotationKeys,
        numVerificationMethods,
        verificationMethod
    }

    mapping(bytes32 => Did) public dids;

    function isAtTip(bytes32 didGenesisHash, bytes32 updateHash) external returns (bool) {
        return (dids[didGenesisHash].updates[updateHash].countChildren > 0);
    }

    function uncontroversialTip(bytes32 didGenesisHash) external returns (bytes32) {
        return dids[didGenesisHash].uncontroversialTip;
    }

    function uncontroversialVerificationAddress(bytes32 didGenesisHash) external returns (address) {
        bytes32 uncontroversialTip = dids[didGenesisHash].uncontroversialTip;
        if (uncontroversialTip == bytes32(0)) {
            return address(0);
        }
        return dids[didGenesisHash].updates[uncontroversialTip].verificationMethod;
    }

    function isForkedAt(bytes32 didGenesisHash, bytes32 updateHash) external returns (bool) {
        return (dids[didGenesisHash].updates[updateHash].countChildren > 1);
    }

    // Returns the address of the verification method as of the update, or 0x0 if it has not been stored
    function verificationAddressAt(bytes32 didGenesisHash, bytes32 updateHash) external returns (address) {
        return dids[didGenesisHash].updates[updateHash].verificationMethod;
    }

    // If your did history has forked, you can choose a fork by marking an update (you would normally choose a tip) legit.
    // This function will tell you if that update, or one of its descendents, has forked.
    function isBranchForkedSince(bytes32 didGenesisHash, bytes32 chosenOpHash, bytes32 tip)
        public
        view
        returns (bool)
    {
        bytes32 op = tip;
        while (op != bytes32(0)) {
            if (dids[didGenesisHash].updates[op].countChildren > 1) {
                return true;
            }
            if (op == chosenOpHash) {
                return false;
            }
            op = dids[didGenesisHash].updates[op].parentHash;
        }
        revert("chosenOpHash not found");
    }

    // This will append an entry to the tree
    // Usually parentHash will be the tip of the tree and we won't be adding a fork
    // But you could be adding a child to something lower down the tree to make a fork
    function registerUpdate(bytes32 didGenesisHash, bytes32 newHash, bytes32 parentHash) internal {
        require(parentHash != bytes32(0), "non-genesis operation must have a parent hash");
        require(dids[didGenesisHash].updates[parentHash].recordedTimestamp > 0, "parentHash not found in chain");
        require(dids[didGenesisHash].updates[newHash].recordedTimestamp == 0, "newHash already registered");

        dids[didGenesisHash].updates[newHash].parentHash = parentHash;
        dids[didGenesisHash].updates[newHash].recordedTimestamp = uint128(block.timestamp);

        uint128 countChildren = dids[didGenesisHash].updates[parentHash].countChildren;

        if (dids[didGenesisHash].uncontroversialTip != bytes32(0)) {
            // If we're adding a child to something that already has one, we just forked the history and we don't have an uncontroversialTip
            if (countChildren > 0) {
                dids[didGenesisHash].uncontroversialTip = bytes32(0);
            } else {
                // If there's already one tip then we're replacing it
                dids[didGenesisHash].uncontroversialTip = newHash;
            }
        }
        dids[didGenesisHash].updates[parentHash].countChildren = countChildren + 1;
        emit LogRegisterUpdate(didGenesisHash, parentHash, newHash);
    }

    // NB You can pass any content you like here and we'll make a DID record for its hash
    // If you want to make a did entry for a picture of your cat that's fine, go right ahead
    // We only care what's in the record if you try to update it
    function registerGenesis(bytes32 entryHash) internal {
        dids[entryHash].didBytes = bytes(abi.encode(entryHash));
        dids[entryHash].updates[entryHash].recordedTimestamp = uint128(block.timestamp);
        dids[entryHash].uncontroversialTip = entryHash;
        emit LogRegisterUpdate(entryHash, bytes32(0), entryHash);
    }

    /// @notice Register a series of update operations to the DID registry
    /// @param didGenesisHash The hash of the first entry which creates the DID ID
    /// @dev If you're starting from genesis you can leave didGenesisHash empty and we'll work it out
    /// @param entries CBOR-encoded bytes representing operations, without their signatures
    /// @dev The first entry you supply should already be registered, unless it's the genesis operation
    /// @param sigs Signatures for each update: 32-byte r, 32-byte s, 1-byte v
    /// @dev The v parameters are not included in the signed CBOR updates, but we need them for ecrecover
    /// @param pubkeys Uncompressed pubkeys of each rotation key used for signing, then the last verification key
    /// @dev Another way would be to recover these by decompressing what we find in the CBOR data, but this way avoids the dependency
    /// @param rotationKeyIndexes The indexes of which rotation key entry provides the key that signs the next entry
    function registerUpdates(
        bytes32 didGenesisHash,
        bytes[] calldata entries,
        bytes[] calldata sigs,
        bytes[] calldata pubkeys,
        uint256[] calldata rotationKeyIndexes
    ) public {
        // Hash of the pre-signature content. We use this internally to track updates.
        bytes32 nextParent;

        // CID using the signature (may vary due to malleability)
        // This is what we expect to find in the "prev" field of the next update
        bytes32 nextPrev;

        // Rotation key that will sign the next entry.
        // There may be many keys so we have the user tell us which we need next with rotationKeyIndexes
        address nextRotationKey;

        for (uint256 i = 0; i < entries.length; i++) {
            bytes32 entryHash = sha256(entries[i]);

            // We never try to verify the first entry.
            // It should either be the genesis entry, in which case there's nothing to verify...
            // ...or a subsequent entry which must have already been registered or registerUpdate() will revert next time.
            if (i == 0) {
                // For convenience you can send an empty did for genesis and let us hash it
                if (didGenesisHash == bytes32(0)) {
                    didGenesisHash = entryHash;
                }
                // If this is the genesis entry, register it if it's not already registered.
                if (entryHash == didGenesisHash && dids[entryHash].didBytes.length == 0) {
                    registerGenesis(entryHash);
                }
            } else {
                require(nextParent != bytes32(0), "entry 1 and later must have a nextParent");
                verifyEntry(entries[i], sigs[i], entryHash, nextPrev, nextRotationKey);
                registerUpdate(didGenesisHash, entryHash, nextParent);
            }

            // Verifying the next entry will need the rotation key and CID value for this entry.

            // last entry
            if (i == entries.length - 1) {
                // We'll store the verification key so you can query it.
                // You probably only care about the key at the tip so we store only the final entry to save gas.
                // But if you want to store an intermediate key for some reason you can call storeVerificationMethod() on it later
                // NB the last pubkey entry is for the verification key, not a rotation key
                _storeVerificationMethod(didGenesisHash, entryHash, entries[i], pubkeys[i]);

                // If there is no next entry then we're done.
                return;
            }

            nextParent = entryHash;

            // To validate "prev" in the next entry we'll need the hash corresponding to the CID
            // entries[i] has the signature removed, so we need to put it back in then hash the resulting CBOR
            // We trim off the final "v" at byte 65
            nextPrev = calculateCIDSha256(entries[i], sigs[i][:64], 1);

            nextRotationKey = extractRotationKey(entries[i], pubkeys[i], rotationKeyIndexes[i]);
        }
    }

    function _storeVerificationMethod(
        bytes32 didGenesisHash,
        bytes32 entryHash,
        bytes calldata entry,
        bytes calldata pubkey
    ) internal {
        require(dids[didGenesisHash].updates[entryHash].recordedTimestamp > 0, "entry not found");
        dids[didGenesisHash].updates[entryHash].verificationMethod = extractVerificationMethod(entry, pubkey);
    }

    function storeVerificationMethod(bytes32 didGenesisHash, bytes calldata entry, bytes calldata pubkey) external {
        bytes32 entryHash = sha256(entry);
        _storeVerificationMethod(didGenesisHash, entryHash, entry, pubkey);
    }
}
