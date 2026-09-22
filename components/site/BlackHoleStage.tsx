import BlackHoleFallback from '@/components/site/BlackHoleFallback';
import styles from '@/components/site/BlackHoleStage.module.css';

export default function BlackHoleStage() {
  return (
    <div className={styles.stage} aria-hidden="true">
      <div className={styles.inner} data-black-hole-fallback>
        <BlackHoleFallback />
      </div>
    </div>
  );
}
