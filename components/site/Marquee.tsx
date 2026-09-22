import { marqueeItems } from '@/content/site';
import styles from '@/components/site/Marquee.module.css';

function Group({ hidden }: { hidden?: boolean }) {
  return (
    <ul className={styles.group} aria-hidden={hidden ? true : undefined}>
      {marqueeItems.map((item) => (
        <li key={item} className={styles.item}>
          <span className={styles.sep} aria-hidden="true">
            +
          </span>
          {item}
        </li>
      ))}
    </ul>
  );
}

export default function Marquee() {
  return (
    <div className={styles.marquee}>
      <div className={styles.track}>
        <Group />
        <Group hidden />
      </div>
    </div>
  );
}
