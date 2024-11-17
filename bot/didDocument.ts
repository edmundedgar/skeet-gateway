import * as plc from '@did-plc/lib'
import { VerificationMethod } from './watcher.js';

const PLC_CLIENT = new plc.Client('https://plc.directory');

let exampleDid = 'did:plc:7mnpet2pvof2llhpcwattscf';

export const getVerificationMethod = async(did: string): Promise<VerificationMethod> => {
    const data = await PLC_CLIENT.getDocumentData(exampleDid);
    const atProtoVerifyMethod = data?.verificationMethods?.atproto;
    if (!atProtoVerifyMethod) {
        throw new Error('No atproto verification method found');
    }
    return {
        id: `${did}#atproto`,
        type: 'Multikey',
        controller: did,
        publicKeyMultibase: atProtoVerifyMethod.replace('did:key:', '')
    }     
}