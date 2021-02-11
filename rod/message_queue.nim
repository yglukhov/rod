import deques, hashes, macros

type
  MessageId* = distinct int
  MessageQueue*[M] = ref object
    messages: Deque[tuple[id: MessageId, msg: M]]

proc toMessageId*(str: string): MessageId = cast[MessageId](hash(str))

proc `==`*(id: MessageId, str: string): bool = int(id) == int(str.toMessageId)

proc `$`*(id: MessageId): string = $(int(id))

proc createMessageQueue*[M](): MessageQueue[M] =
  result = new(MessageQueue[M])
  result.messages = initDeque[tuple[id: MessageId, msg: M]]()

proc post*[M](q: MessageQueue[M], id: string, m: M = default(M)) =
  q.messages.addLast((id: id.toMessageId, msg: m))

proc isEmpty*[M](q: MessageQueue[M]): bool = q.messages.len == 0

iterator popChunk*[M](q: MessageQueue[M], chunk: int = 100): tuple[id: MessageId, msg:M] =
  var i = 0
  while q.messages.len > 0 and i < chunk:
    var v = q.messages.popFirst()
    yield v
    inc i
