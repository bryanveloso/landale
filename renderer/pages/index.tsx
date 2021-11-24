import Head from 'next/head'
import Link from 'next/link'
import Image from 'next/image'

export default function Home() {
  return (
    <div>
      <Head>
        <title>Landale</title>
      </Head>

      <main>
        <Link href="/activity">Activity</Link>
        <Link href="/outro">Outro</Link>
      </main>
    </div>
  )
}
