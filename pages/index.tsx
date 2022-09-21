import { GetServerSideProps, InferGetServerSidePropsType } from 'next'
import Head from 'next/head'

const Home = ({
  host
}: InferGetServerSidePropsType<typeof getServerSideProps>) => {
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

export const getServerSideProps: GetServerSideProps = async context => {
  const host = context.req.headers.host

  return {
    props: { host }
  }
}
