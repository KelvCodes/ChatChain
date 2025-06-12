export const idlFactory = ({ IDL }) => {
    const Message = IDL.Record({
      'content': IDL.Text,
      'sender': IDL.Principal,
      'timestamp': IDL.Int,
    });
    return IDL.Service({
      'clearMessages': IDL.Func([], [], []),
      'getMessages': IDL.Func([], [IDL.Vec(Message)], ['query']),
      'getMessagesSince': IDL.Func([IDL.Int], [IDL.Vec(Message)], ['query']),
      'getUsers': IDL.Func([], [IDL.Vec(IDL.Tuple(IDL.Principal, IDL.Text))], ['query']),
      'registerUser': IDL.Func([IDL.Text], [IDL.Bool], []),
      'sendMessage': IDL.Func([IDL.Text], [], []),
    });
  };
  export const init = ({ IDL }) => { return []; };