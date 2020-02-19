import NIO

protocol SrtChannel: Channel {
    func socket() -> SrtBaseSocket

    func readTrigger()

    func writeTrigger()

    func errorTrigger()
}
