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
    event LogRegisterUpdate(bytes32 did, bytes32 parentHash, bytes32 newHash);

    // We will keep an update record for every item including the genesis operation
    struct UpdateOp {
        bytes32 parentHash;
        uint128 countChildren;
        uint128 recordedTimestamp;
        address verificationMethod;
    }

    struct Did {
        bytes32 entryHash; // The hash of the unsigned first entry
        bytes32 uncontroversialTip; // The tip of the chain, or 0x0 if the chain has forked
        mapping(bytes32 => UpdateOp) updates;
        mapping(bytes32 => bytes32) accountBlessedUpdates;
    }

    mapping(bytes32 => Did) public dids;

    /// @notice Whether the specified update is at the tip (ie has no children)
    /// @param did The did
    /// @param updateHash The update
    /// @return True if the update is at the tip
    function isAtTip(bytes32 did, bytes32 updateHash) external view returns (bool) {
        return (dids[did].updates[updateHash].countChildren > 0);
    }

    /// @notice The update at the tip of the chain, if it has not forked
    /// @param did The did
    /// @return The update hash if the chain has not forked, or 0x0 if it has
    function uncontroversialTip(bytes32 did) external view returns (bytes32) {
        return dids[did].uncontroversialTip;
    }

    /// @notice Signer says that an update was correct
    /// @dev Anyone can express an opinion about any update of any did
    /// @dev Probably only the signer of that did will have an opinion that anything depends on
    /// @param did The did to operate
    function blessUpdate(bytes32 did, bytes32 updateHash) external {
        bytes32 account = keccak256(abi.encodePacked(did, msg.sender));
        require(dids[did].updates[updateHash].recordedTimestamp > 0, "Update not found");
        dids[did].accountBlessedUpdates[account] = updateHash;
    }

    /// @notice The verification address of the update at the tip of the chain, if it has not forked
    /// @param did The did
    /// @return The verification address if the chain has not forked, or 0x0 if it has
    function uncontroversialVerificationAddress(bytes32 did) external view returns (address) {
        bytes32 tip = dids[did].uncontroversialTip;
        if (tip == bytes32(0)) {
            return address(0);
        }
        return dids[did].updates[tip].verificationMethod;
    }

    /// @notice Whether the specified update has a fork, ie has multiple children
    /// @param did The did
    /// @param updateHash The update at which you want to know the whether there was a fork
    /// @return True if the update history forks at this update
    function isForkedAt(bytes32 did, bytes32 updateHash) external view returns (bool) {
        return (dids[did].updates[updateHash].countChildren > 1);
    }

    /// @notice Return the verification method address as of the specific update, if it has been stored
    /// @dev We do not always store the verification method address, so it may be 0x0 even though there is one
    /// @param did The did
    /// @param updateHash The update at which you want to know the verification address
    /// @return The verification method address as of the specific update, if it has been stored
    function verificationAddressAt(bytes32 did, bytes32 updateHash) external view returns (address) {
        return dids[did].updates[updateHash].verificationMethod;
    }

    /// @notice Return whether the history of the DID has forked between the specified update and the specified tip
    /// @dev If your did history has forked, you can choose a fork by marking an update (you would normally choose a tip) legit.
    /// @dev This function is designed to tell you if that update, or one of its descendents, has forked.
    /// @param did The did you are updating
    /// @param chosenOpHash The lowest update to consider from the tip
    /// @param tip The tip of the branch you are interested in
    /// @return True if the chain has forked between the chosenOpHash and the tip
    function isBranchForkedSince(bytes32 did, bytes32 chosenOpHash, bytes32 tip) public view returns (bool) {
        bytes32 op = tip;
        while (op != bytes32(0)) {
            if (dids[did].updates[op].countChildren > 1) {
                return true;
            }
            if (op == chosenOpHash) {
                return false;
            }
            op = dids[did].updates[op].parentHash;
        }
        revert("chosenOpHash not found");
    }

    /// @notice Register a DID update
    /// @dev This will append an entry to the tree
    /// @dev Usually parentHash will be the tip of the tree and we will just be extending it
    /// @dev But you could be adding a child to something lower down the tree to make a fork
    /// @param did The did you are updating
    /// @param newHash The hash of the entry you are adding
    /// @param parentHash The hash of the entry you are appending to
    function registerUpdate(bytes32 did, bytes32 newHash, bytes32 parentHash) internal {
        require(parentHash != bytes32(0), "non-genesis operation must have a parent hash");
        require(dids[did].updates[parentHash].recordedTimestamp > 0, "parentHash not found in chain");
        require(dids[did].updates[newHash].recordedTimestamp == 0, "newHash already registered");

        dids[did].updates[newHash].parentHash = parentHash;
        dids[did].updates[newHash].recordedTimestamp = uint128(block.timestamp);

        uint128 countChildren = dids[did].updates[parentHash].countChildren;

        if (dids[did].uncontroversialTip != bytes32(0)) {
            // If we're adding a child to something that already has one, we just forked the history and we don't have an uncontroversialTip
            if (countChildren > 0) {
                dids[did].uncontroversialTip = bytes32(0);
            } else {
                // If there's already one tip then we're replacing it
                dids[did].uncontroversialTip = newHash;
            }
        }
        dids[did].updates[parentHash].countChildren = countChildren + 1;
        emit LogRegisterUpdate(did, parentHash, newHash);
    }

    /// @notice Register a DID record and an entry for the first (genesis) update
    /// @param entryHash The hash of the first entry which creates the DID ID
    /// @dev NB You can pass any content you like here and we'll make a DID record for its hash
    /// @dev If you want to make a did entry for a picture of your cat that's fine, go right ahead
    /// @dev We only care what's in the record if you try to query or update it
    function registerGenesis(bytes32 entryHash, bytes32 nextPrev) internal returns (bytes32) {
        bytes32 did = genesisHashToDidKey(nextPrev);
        dids[did].entryHash = entryHash;
        dids[did].uncontroversialTip = entryHash;
        dids[did].updates[entryHash].recordedTimestamp = uint128(block.timestamp);
        emit LogRegisterUpdate(did, bytes32(0), entryHash);
        return did;
    }

    /// @notice Register a series of update operations to the DID registry
    /// @param did The did you want to update, or 0x0 if you are creating it for the first time
    /// @param entries CBOR-encoded bytes representing operations, without their signatures
    /// @dev The first entry you supply should already be registered, unless it's the genesis operation
    /// @param sigs Signatures for each update: 32-byte r, 32-byte s, 1-byte v
    /// @dev The v parameters are not included in the signed CBOR updates, but we need them for ecrecover
    /// @param pubkeys Uncompressed pubkeys of each rotation key used for signing, then the last verification key
    /// @dev Another way would be to recover these by decompressing what we find in the CBOR data, but this way avoids the dependency
    /// @param rotationKeyIndexes The indexes of which rotation key entry provides the key that signs the next entry
    function registerUpdates(
        bytes32 did,
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
            // ...or a subsequent entry which should already have been registered and we just need it to extract the prev/key
            if (i == 0) {
                // To calculate the DID we will need the hash of the signed version of the entry.
                // entries[i] has the signature removed, so we need to put it back in then hash the resulting CBOR
                // We trim off the final "v" at byte 65
                // This will also be used to validate the next entry
                nextPrev = calculateCIDSha256(entries[i], sigs[i][:64]);
                if (did == bytes32(0)) {
                    did = registerGenesis(entryHash, nextPrev);
                }
            } else {
                require(nextParent != bytes32(0), "entry 1 and later must have a nextParent");
                verifyEntry(entries[i], sigs[i], entryHash, nextPrev, nextRotationKey);
                registerUpdate(did, entryHash, nextParent);

                // Hash the signed version to verify the next entry, if there is one.
                if (i < entries.length - 1) {
                    nextPrev = calculateCIDSha256(entries[i], sigs[i][:64]);
                }
            }

            if (i < entries.length - 1) {
                // Next entry also needs our unsigned hash and the rotation key it will sign with
                nextParent = entryHash;
                nextRotationKey = extractRotationKey(entries[i], pubkeys[i], rotationKeyIndexes[i]);
            } else {
                // We'll store the verification key so you can query it.
                // You probably only care about the key at the tip so we store only the final entry to save gas.
                // But if you want to store an intermediate key for some reason you can call storeVerificationMethod() on it later
                // NB this last pubkey entry is for the verification key, not a rotation key
                _storeVerificationMethod(did, entryHash, entries[i], pubkeys[i]);
            }
        }
    }

    /// @notice Store the verification method address for an update
    /// @param did The hash of the first entry which creates the DID ID
    /// @param entryHash The hash of the first entry which creates the DID ID
    /// @param entry The entry in which we should find the pubkey
    /// @param pubkey The pubkey we expect to find, but as an uncompressed pubkey
    function _storeVerificationMethod(bytes32 did, bytes32 entryHash, bytes calldata entry, bytes calldata pubkey)
        internal
    {
        require(dids[did].updates[entryHash].recordedTimestamp > 0, "entry not found");
        dids[did].updates[entryHash].verificationMethod = extractVerificationMethod(entry, pubkey);
    }

    /// @notice Store the verification method address for an update which is otherwise already registered
    /// @dev This is stored automatically by registerUpdates when adding to the tip.
    /// @dev You only need it if you want to be able to read the address of an intermediate update for some reason.
    /// @param did The hash of the first entry which creates the DID ID
    /// @param entry The entry in which we should find the pubkey
    /// @param pubkey The pubkey we expect to find, but as an uncompressed pubkey
    function storeVerificationMethod(bytes32 did, bytes calldata entry, bytes calldata pubkey) external {
        bytes32 entryHash = sha256(entry);
        _storeVerificationMethod(did, entryHash, entry, pubkey);
    }
}
