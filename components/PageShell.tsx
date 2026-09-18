import styles from '@/components/layout.module.css';

export default function PageShell({
  children,
}: {
  children: React.ReactNode;
}) {
  return <div className={styles.container}>{children}</div>;
}
