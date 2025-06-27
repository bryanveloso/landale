import * as React from 'react'

interface TabsProps extends React.HTMLAttributes<HTMLDivElement> {
  defaultValue?: string
  value?: string
  onValueChange?: (value: string) => void
}

interface TabsContextValue {
  value: string
  onValueChange: (value: string) => void
}

const TabsContext = React.createContext<TabsContextValue | undefined>(undefined)

const Tabs = React.forwardRef<HTMLDivElement, TabsProps>(
  ({ defaultValue = '', value: controlledValue, onValueChange, children, ...props }, ref) => {
    const [uncontrolledValue, setUncontrolledValue] = React.useState(defaultValue)
    const value = controlledValue ?? uncontrolledValue

    const handleValueChange = React.useCallback(
      (newValue: string) => {
        if (controlledValue === undefined) {
          setUncontrolledValue(newValue)
        }
        onValueChange?.(newValue)
      },
      [controlledValue, onValueChange]
    )

    return (
      <TabsContext.Provider value={{ value, onValueChange: handleValueChange }}>
        <div ref={ref} {...props}>
          {children}
        </div>
      </TabsContext.Provider>
    )
  }
)
Tabs.displayName = 'Tabs'

const TabsList = React.forwardRef<HTMLDivElement, React.HTMLAttributes<HTMLDivElement>>(
  ({ className = '', ...props }, ref) => (
    <div
      ref={ref}
      className={`bg-muted text-muted-foreground inline-flex h-10 items-center justify-center rounded-md p-1 ${className}`}
      {...props}
    />
  )
)
TabsList.displayName = 'TabsList'

interface TabsTriggerProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  value: string
}

const TabsTrigger = React.forwardRef<HTMLButtonElement, TabsTriggerProps>(
  ({ className = '', value, ...props }, ref) => {
    const context = React.useContext(TabsContext)
    if (!context) {
      throw new Error('TabsTrigger must be used within Tabs')
    }

    const isSelected = context.value === value

    return (
      <button
        ref={ref}
        type="button"
        role="tab"
        aria-selected={isSelected}
        onClick={() => {
          context.onValueChange(value)
        }}
        className={`ring-offset-background inline-flex items-center justify-center rounded-sm px-3 py-1.5 text-sm font-medium whitespace-nowrap transition-all ${
          isSelected ? 'bg-background text-foreground shadow-sm' : 'hover:bg-background/50'
        } ${className}`}
        {...props}
      />
    )
  }
)
TabsTrigger.displayName = 'TabsTrigger'

interface TabsContentProps extends React.HTMLAttributes<HTMLDivElement> {
  value: string
}

const TabsContent = React.forwardRef<HTMLDivElement, TabsContentProps>(({ value, ...props }, ref) => {
  const context = React.useContext(TabsContext)
  if (!context) {
    throw new Error('TabsContent must be used within Tabs')
  }

  if (context.value !== value) {
    return null
  }

  return <div ref={ref} {...props} />
})
TabsContent.displayName = 'TabsContent'

export { Tabs, TabsList, TabsTrigger, TabsContent }
