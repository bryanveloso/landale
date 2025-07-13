export function Button(props: any) {
  const { variant = 'default', size = 'default', class: className, ...rest } = props
  const classes = `button button-${variant} button-${size} ${className || ''}`.trim()
  return <button class={classes} {...rest} />
}
