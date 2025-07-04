import { Omnibar } from './components/Omnibar'

function App() {
  return (
    <div>
      <Omnibar serverUrl="ws://localhost:4000/socket" />
    </div>
  )
}

export default App
