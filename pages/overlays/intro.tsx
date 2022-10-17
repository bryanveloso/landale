import { GetServerSideProps, InferGetServerSidePropsType } from 'next'
import { Wallpaper } from '~/components/overlays'

const Intro = ({}: InferGetServerSidePropsType<typeof getServerSideProps>) => {
  return (
    <div>
      <Wallpaper />
    </div>
  )
}

export default Intro

export const getServerSideProps: GetServerSideProps<{}> = async context => {
  return {
    props: {}
  }
}
