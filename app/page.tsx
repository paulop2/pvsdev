import Footer from '@/components/site/Footer';
import Hero from '@/components/site/Hero';
import Projects from '@/components/site/Projects';
import Services from '@/components/site/Services';
import Stack from '@/components/site/Stack';
import Writing from '@/components/site/Writing';

export default function Home() {
  return (
    <>
      <Hero />
      <Services />
      <Projects />
      <Stack />
      <Writing />
      <Footer />
    </>
  );
}
