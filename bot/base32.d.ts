declare module "base32" {
  export function encode(data: Uint8Array | Buffer): string;
  export function decode(str: string): Buffer;
}
