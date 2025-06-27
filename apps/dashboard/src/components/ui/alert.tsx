import * as React from 'react'

interface AlertProps extends React.HTMLAttributes<HTMLDivElement> {
  variant?: 'default' | 'destructive'
}

const Alert = React.forwardRef<HTMLDivElement, AlertProps>(({ className = '', variant = 'default', ...props }, ref) => {
  const variantClasses = {
    default: 'bg-background text-foreground',
    destructive: 'bg-destructive/10 text-destructive'
  }

  return (
    <div
      ref={ref}
      role="alert"
      className={`relative w-full rounded-lg border p-4 ${variantClasses[variant]} ${className}`}
      {...props}
    />
  )
})
Alert.displayName = 'Alert'

const AlertTitle = React.forwardRef<HTMLHeadingElement, React.HTMLAttributes<HTMLHeadingElement>>(
  ({ className = '', ...props }, ref) => (
    <h5 ref={ref} className={`mb-1 leading-none font-medium tracking-tight ${className}`} {...props} />
  )
)
AlertTitle.displayName = 'AlertTitle'

const AlertDescription = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(
  ({ className = '', ...props }, ref) => (
    <div ref={ref} className={`text-sm [&_p]:leading-relaxed ${className}`} {...props} />
  )
)
AlertDescription.displayName = 'AlertDescription'

export { Alert, AlertTitle, AlertDescription }
