export function Button(props: any) {
  return <button data-button data-variant={props.variant || 'default'} data-size={props.size || 'default'} {...props} />
}
