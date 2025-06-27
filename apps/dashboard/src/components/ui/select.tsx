import * as React from 'react'

type SelectProps = React.SelectHTMLAttributes<HTMLSelectElement>

const Select = React.forwardRef<HTMLSelectElement, SelectProps>(({ className = '', ...props }, ref) => (
  <select
    ref={ref}
    className={`border-input bg-background ring-offset-background flex h-10 w-full rounded-md border px-3 py-2 text-sm ${className}`}
    {...props}
  />
))
Select.displayName = 'Select'

type SelectContentProps = React.HTMLAttributes<HTMLDivElement>

const SelectContent = React.forwardRef<HTMLDivElement, SelectContentProps>(({ children, ...props }, ref) => (
  <div ref={ref} {...props}>
    {children}
  </div>
))
SelectContent.displayName = 'SelectContent'

type SelectItemProps = React.OptionHTMLAttributes<HTMLOptionElement>

const SelectItem = React.forwardRef<HTMLOptionElement, SelectItemProps>(({ children, ...props }, ref) => (
  <option ref={ref} {...props}>
    {children}
  </option>
))
SelectItem.displayName = 'SelectItem'

type SelectTriggerProps = React.HTMLAttributes<HTMLDivElement>

const SelectTrigger = React.forwardRef<HTMLDivElement, SelectTriggerProps>(({ children, ...props }, ref) => (
  <div ref={ref} {...props}>
    {children}
  </div>
))
SelectTrigger.displayName = 'SelectTrigger'

interface SelectValueProps extends React.HTMLAttributes<HTMLSpanElement> {
  placeholder?: string
}

const SelectValue = React.forwardRef<HTMLSpanElement, SelectValueProps>(({ placeholder, ...props }, ref) => (
  <span ref={ref} {...props}>
    {placeholder}
  </span>
))
SelectValue.displayName = 'SelectValue'

export { Select, SelectContent, SelectItem, SelectTrigger, SelectValue }
