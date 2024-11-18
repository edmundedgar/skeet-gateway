import * as plc from '@did-plc/lib'
import { VerificationMethod } from './watcher.js';

const PLC_CLIENT = new plc.Client('https://plc.directory');

let exampleDid = 'did:plc:7mnpet2pvof2llhpcwattscf';

export type VerificationMethodMap = {
    [did: string]: VerificationMethod;
}

/// ignore that this will need to invalidate methods after rotation for now
let VERIFY_METHOD_CACHE: VerificationMethodMap = {};

export const getVerificationMethod = async(did: string): Promise<VerificationMethod> => {
    const cacheEntry = VERIFY_METHOD_CACHE[did];
    if (cacheEntry) {
        return cacheEntry;
    }
    
    const data = await PLC_CLIENT.getDocumentData(exampleDid);
    const atProtoVerifyMethod = data?.verificationMethods?.atproto;
    if (!atProtoVerifyMethod) {
        throw new Error('No atproto verification method found');
    }
    const method = {
        id: `${did}#atproto`,
        type: 'Multikey',
        controller: did,
        publicKeyMultibase: atProtoVerifyMethod.replace('did:key:', '')
    };
    
    VERIFY_METHOD_CACHE[did] = method;
    return method;
}