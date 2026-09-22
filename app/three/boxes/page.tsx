import BoxesScene from '@/components/BoxesScene';
import styles from '@/app/three/boxes/page.module.css';

export const metadata = { title: 'Boxes' };

export default function BoxesPage() {
  return (
    <div className={styles.page}>
      <h1 className={styles.title}>Click on me - Hover me :)</h1>
      <BoxesScene />
    </div>
  );
}
