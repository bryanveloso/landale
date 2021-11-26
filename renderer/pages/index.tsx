import Head from 'next/head'
import { GetServerSideProps } from 'next'
import { getLayout } from '@landale/layouts/for-app'

const Home = ({ host }) => {
  return (
    <div>
      <Head>
        <title>Landale</title>
      </Head>

      <main>
        <h1>Overlay Listing</h1>
        <input value={`${host}/activity`} readOnly />
        <input value={`${host}/outro`} readOnly />
      </main>
    </div>
  )
}

export default Home

Home.getLayout = getLayout

export const getServerSideProps: GetServerSideProps = async context => {
  const host = context.req.headers.host

  return {
    props: { host }
  }
}
