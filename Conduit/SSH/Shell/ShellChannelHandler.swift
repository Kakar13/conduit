import Foundation
import NIOCore
import NIOSSH

/// Reads data from the SSH shell channel and forwards raw bytes to the
/// terminal. Both stdout and stderr are streamed to the same surface, as
/// with any interactive shell.
final class ShellChannelHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = SSHChannelData

    private let onOutput: @Sendable (Data) -> Void

    init(onOutput: @escaping @Sendable (Data) -> Void) {
        self.onOutput = onOutput
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case .byteBuffer(let buffer) = channelData.data else { return }
        onOutput(Data(buffer.readableBytesView))
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
