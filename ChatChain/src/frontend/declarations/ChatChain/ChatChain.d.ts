import type { Actor, HttpAgent } from '@dfinity/agent';

export interface Message {
  'content': string,
  'sender': Principal,
  'timestamp': bigint,
}
export interface _SERVICE {
  'clearMessages': () => Promise<undefined>,
  'getMessages': () => Promise<Array<Message>>,
  'getMessagesSince': (arg_0: bigint) => Promise<Array<Message>>,
  'getUsers': () => Promise<Array<[Principal, string]>>,
  'registerUser': (arg_0: string) => Promise<boolean>,
  'sendMessage': (arg_0: string) => Promise<undefined>,
}
export declare const idlFactory: ({ IDL }: { IDL: any }) => any;
export declare const init: (args: { IDL: any }) => any[];