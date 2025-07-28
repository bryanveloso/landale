import type { JSX } from 'solid-js'

interface ButtonProps extends JSX.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'default' | 'primary' | 'secondary' | 'danger' | 'outline' | 'destructive'
  size?: 'default' | 'small' | 'large' | 'sm'
  class?: string
}

export function Button(props: ButtonProps) {
  const { variant = 'default', size = 'default', class: className, ...rest } = props
  const classes = `button button-${variant} button-${size} ${className || ''}`.trim()
  return <button class={classes} {...rest} />
}
