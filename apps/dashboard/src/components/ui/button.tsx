import { splitProps, type JSX } from 'solid-js'

interface ButtonProps extends JSX.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'default' | 'primary' | 'secondary' | 'danger' | 'outline' | 'destructive'
  size?: 'default' | 'small' | 'large' | 'sm'
  class?: string
}

export function Button(props: ButtonProps) {
  const [local, rest] = splitProps(props, ['variant', 'size', 'class', 'children'])
  const variant = local.variant || 'default'
  const size = local.size || 'default'
  const classes = `button button-${variant} button-${size} ${local.class || ''}`.trim()

  return (
    <button class={classes} {...rest}>
      {local.children}
    </button>
  )
}
