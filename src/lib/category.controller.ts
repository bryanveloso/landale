import ObsController from './obs.controller'
import { CustomServer } from './server'
import type { TwitchChannelUpdateEvent } from './twitch.controller'

export default class CategoryController {
  private server: CustomServer
  private obs: ObsController

  private currentCategory: string
  private previousCategory: string

  constructor(server: CustomServer, obs: ObsController) {
    this.server = server
    this.obs = obs

    this.currentCategory = ''
    this.previousCategory = ''

    this.initCategoryController()
  }

  private initCategoryController() {
    this.server.on('update', (event: TwitchChannelUpdateEvent) => {
      event && this.updateCategory(event.event.category_name)
    })
  }

  async updateCategory(category_name: string) {
    if (category_name === this.currentCategory) {
      return
    }

    this.previousCategory = this.currentCategory
    console.log(` ➡️ Category changed to: "${category_name}"`)
    this.currentCategory = category_name

    switch (category_name) {
      case 'Words on Stream':
        await this.obs.setScene('[🎬] Words on Stream')
        break

      default:
        break
    }
  }
}
