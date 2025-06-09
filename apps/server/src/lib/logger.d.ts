declare class PrettyLogger {
  private module
  constructor(module: string)
  info(message: string, ...args: unknown[]): void
  error(message: string, error?: Error | unknown, ...args: unknown[]): void
  warn(message: string, ...args: unknown[]): void
  debug(message: string, ...args: unknown[]): void
}
export declare const logger: PrettyLogger
export declare const createLogger: (module: string) => PrettyLogger
export {}
//# sourceMappingURL=logger.d.ts.map
