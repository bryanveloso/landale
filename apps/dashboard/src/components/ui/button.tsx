export function Button(props: any) {
  return (
    <button
      class="inline-flex items-center justify-center rounded-md bg-onyx px-3 py-2 text-sm font-medium text-chalk shadow-sm hover:bg-chalk hover:text-onyx focus:outline-none focus:ring-2 focus:ring-chalk focus:ring-offset-2 disabled:opacity-50 disabled:pointer-events-none"
      {...props}
    />
  )
}
