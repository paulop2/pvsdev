import Link from 'next/link'
import { FiArrowLeft } from 'react-icons/fi'
// import Layout from '../components/layout'


export default function BackToHome() {
  return (
    <div>
      <h2>
        <Link href="/" >
          <FiArrowLeft size={24} color="#fff" />
        </Link>
      </h2>
    </div>
  )
}
