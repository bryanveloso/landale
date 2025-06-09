export interface Context {
  req?: Request
}
export declare const router: <TInput extends import('@trpc/server/unstable-core-do-not-import').CreateRouterOptions>(
  input: TInput
) => import('@trpc/server/unstable-core-do-not-import').BuiltRouter<
  {
    ctx: Context
    meta: object
    errorShape: {
      data: {
        zodError: import('zod').typeToFlattenedError<any, string> | null
        code: import('@trpc/server/unstable-core-do-not-import').TRPC_ERROR_CODE_KEY
        httpStatus: number
        path?: string
        stack?: string
      }
      message: string
      code: import('@trpc/server/unstable-core-do-not-import').TRPC_ERROR_CODE_NUMBER
    }
    transformer: false
  },
  import('@trpc/server/unstable-core-do-not-import').DecorateCreateRouterOptions<TInput>
>
export declare const publicProcedure: import('@trpc/server/unstable-core-do-not-import').ProcedureBuilder<
  Context,
  object,
  {
    req: Request | undefined
  },
  typeof import('@trpc/server/unstable-core-do-not-import').unsetMarker,
  typeof import('@trpc/server/unstable-core-do-not-import').unsetMarker,
  typeof import('@trpc/server/unstable-core-do-not-import').unsetMarker,
  typeof import('@trpc/server/unstable-core-do-not-import').unsetMarker,
  false
>
export declare const authedProcedure: import('@trpc/server/unstable-core-do-not-import').ProcedureBuilder<
  Context,
  object,
  {
    req: Request | undefined
  },
  typeof import('@trpc/server/unstable-core-do-not-import').unsetMarker,
  typeof import('@trpc/server/unstable-core-do-not-import').unsetMarker,
  typeof import('@trpc/server/unstable-core-do-not-import').unsetMarker,
  typeof import('@trpc/server/unstable-core-do-not-import').unsetMarker,
  false
>
//# sourceMappingURL=trpc.d.ts.map
