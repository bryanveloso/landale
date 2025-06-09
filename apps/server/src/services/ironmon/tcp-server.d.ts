interface TCPServerOptions {
  port?: number
  hostname?: string
}
export declare class IronmonTCPServer {
  private server?
  private buffer
  private options
  constructor(options?: TCPServerOptions)
  /**
   * Handles incoming socket connections
   */
  private handleOpen
  /**
   * Handles incoming data from the socket
   * Messages are length-prefixed: "LENGTH MESSAGE" (e.g., "23 {"type":"init",...}")
   */
  private handleData
  /**
   * Processes a single IronMON message
   */
  private processMessage
  /**
   * Handles socket closure
   */
  private handleClose
  /**
   * Handles socket errors
   */
  private handleError
  /**
   * Starts the TCP server
   */
  start(): Promise<void>
  /**
   * Stops the TCP server
   */
  stop(): Promise<void>
}
export declare const ironmonTCPServer: IronmonTCPServer
export {}
//# sourceMappingURL=tcp-server.d.ts.map
