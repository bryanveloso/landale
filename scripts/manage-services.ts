#!/usr/bin/env bun
import { $ } from 'bun'
import { services } from '@landale/service-config'
import chalk from 'chalk'

// Map services to their host machines
const SERVICE_LOCATIONS = {
  server: 'saya',
  overlays: 'saya',
  phononmaser: 'zelan',
  lmStudio: 'zelan'
} as const

// Services managed by Docker instead of PM2
const DOCKER_SERVICES = ['server', 'overlays', 'db']

// Commands
const COMMANDS = {
  status: 'Check status of all services',
  start: 'Start a service',
  stop: 'Stop a service',
  restart: 'Restart a service',
  logs: 'View service logs',
  deploy: 'Deploy latest code and restart'
} as const

async function checkServiceStatus(service: string, host: string) {
  try {
    const isHealthy = await services.healthCheck(service)
    const status = isHealthy ? chalk.green('✓ healthy') : chalk.red('✗ unhealthy')
    console.log(`${chalk.blue(service.padEnd(15))} on ${chalk.yellow(host.padEnd(10))} ${status}`)
  } catch (error) {
    console.log(`${chalk.blue(service.padEnd(15))} on ${chalk.yellow(host.padEnd(10))} ${chalk.gray('unknown')}`)
  }
}

async function runOnHost(host: string, command: string) {
  try {
    const result = await $`ssh ${host} "${command}"`
    return result.stdout.toString()
  } catch (error) {
    console.error(chalk.red(`Failed to run on ${host}: ${error}`))
    return null
  }
}

async function status() {
  console.log(chalk.bold('\n🔍 Checking service health...\n'))

  for (const [service, host] of Object.entries(SERVICE_LOCATIONS)) {
    await checkServiceStatus(service, host)
  }

  console.log('')
}

async function start(serviceName?: string) {
  if (!serviceName) {
    console.error(chalk.red('Please specify a service to start'))
    return
  }

  const host = SERVICE_LOCATIONS[serviceName as keyof typeof SERVICE_LOCATIONS]
  if (!host) {
    console.error(chalk.red(`Unknown service: ${serviceName}`))
    return
  }

  console.log(chalk.blue(`Starting ${serviceName} on ${host}...`))

  if (DOCKER_SERVICES.includes(serviceName)) {
    await runOnHost(host, `cd /opt/landale && docker compose up -d ${serviceName}`)
  } else {
    await runOnHost(host, `cd /opt/landale && pm2 start ecosystem/${host}.config.cjs --only ${serviceName}`)
  }
}

async function stop(serviceName?: string) {
  if (!serviceName) {
    console.error(chalk.red('Please specify a service to stop'))
    return
  }

  const host = SERVICE_LOCATIONS[serviceName as keyof typeof SERVICE_LOCATIONS]
  if (!host) {
    console.error(chalk.red(`Unknown service: ${serviceName}`))
    return
  }

  console.log(chalk.blue(`Stopping ${serviceName} on ${host}...`))

  if (DOCKER_SERVICES.includes(serviceName)) {
    await runOnHost(host, `cd /opt/landale && docker compose stop ${serviceName}`)
  } else {
    await runOnHost(host, `pm2 stop ${serviceName}`)
  }
}

async function restart(serviceName?: string) {
  if (!serviceName) {
    console.error(chalk.red('Please specify a service to restart'))
    return
  }

  const host = SERVICE_LOCATIONS[serviceName as keyof typeof SERVICE_LOCATIONS]
  if (!host) {
    console.error(chalk.red(`Unknown service: ${serviceName}`))
    return
  }

  console.log(chalk.blue(`Restarting ${serviceName} on ${host}...`))

  if (DOCKER_SERVICES.includes(serviceName)) {
    await runOnHost(host, `cd /opt/landale && docker compose restart ${serviceName}`)
  } else {
    await runOnHost(host, `pm2 restart ${serviceName}`)
  }
}

async function logs(serviceName?: string) {
  if (!serviceName) {
    console.error(chalk.red('Please specify a service'))
    return
  }

  const host = SERVICE_LOCATIONS[serviceName as keyof typeof SERVICE_LOCATIONS]
  if (!host) {
    console.error(chalk.red(`Unknown service: ${serviceName}`))
    return
  }

  console.log(chalk.blue(`Streaming logs for ${serviceName} on ${host}...`))
  console.log(chalk.gray('Press Ctrl+C to stop\n'))

  // Stream logs in real-time
  const command = DOCKER_SERVICES.includes(serviceName)
    ? `cd /opt/landale && docker compose logs -f ${serviceName}`
    : `pm2 logs ${serviceName} --lines 50`

  const proc = Bun.spawn(['ssh', host, command], {
    stdout: 'inherit',
    stderr: 'inherit'
  })

  await proc.exited
}

async function deploy(serviceName?: string) {
  const host = serviceName ? SERVICE_LOCATIONS[serviceName as keyof typeof SERVICE_LOCATIONS] : null

  if (serviceName && !host) {
    console.error(chalk.red(`Unknown service: ${serviceName}`))
    return
  }

  const hosts = host ? [host] : [...new Set(Object.values(SERVICE_LOCATIONS))]

  for (const targetHost of hosts) {
    console.log(chalk.bold(`\n📦 Deploying to ${targetHost}...\n`))

    // Pull latest code
    console.log(chalk.blue('Pulling latest code...'))
    await runOnHost(targetHost, 'cd /opt/landale && git pull')

    // Install dependencies
    console.log(chalk.blue('Installing dependencies...'))
    await runOnHost(targetHost, 'cd /opt/landale && bun install')

    // Build
    console.log(chalk.blue('Building services...'))
    await runOnHost(targetHost, 'cd /opt/landale && bun run build')

    // Restart services on this host
    const servicesOnHost = Object.entries(SERVICE_LOCATIONS)
      .filter(([_, h]) => h === targetHost)
      .map(([s]) => s)

    for (const service of servicesOnHost) {
      console.log(chalk.blue(`Restarting ${service}...`))
      await runOnHost(targetHost, `pm2 restart ${service}`)
    }
  }

  console.log(chalk.green('\n✅ Deployment complete!\n'))
}

// Main CLI
async function main() {
  const [command, ...args] = process.argv.slice(2)

  if (!command || command === 'help') {
    console.log(chalk.bold('\n🚀 Landale Service Manager\n'))
    console.log('Usage: bun run manage [command] [service]\n')
    console.log('Commands:')
    for (const [cmd, desc] of Object.entries(COMMANDS)) {
      console.log(`  ${chalk.blue(cmd.padEnd(10))} ${desc}`)
    }
    console.log('\nServices:')
    for (const [service, host] of Object.entries(SERVICE_LOCATIONS)) {
      console.log(`  ${chalk.yellow(service.padEnd(15))} (on ${host})`)
    }
    console.log('')
    return
  }

  switch (command) {
    case 'status':
      await status()
      break
    case 'start':
      await start(args[0])
      break
    case 'stop':
      await stop(args[0])
      break
    case 'restart':
      await restart(args[0])
      break
    case 'logs':
      await logs(args[0])
      break
    case 'deploy':
      await deploy(args[0])
      break
    default:
      console.error(chalk.red(`Unknown command: ${command}`))
      console.log('Run "bun run manage help" for usage')
  }
}

main().catch(console.error)
