interface Game {
  name: string
  wallpaper: string
}

const games: Game[] = [
  { name: 'Default', wallpaper: '/wallpaper/default.png' },
  { name: 'Destiny 2', wallpaper: '/wallpaper/destiny-2.jpeg' },
  { name: 'Final Fantasy XIV Online', wallpaper: '/wallpaper/ffxiv.png' },
  { name: 'Genshin Impact', wallpaper: '/wallpaper/genshin.jpeg' },
  { name: 'Pokémon FireRed/LeafGreen', wallpaper: '/wallpaper/pokemon.jpeg' }
]

export default games
