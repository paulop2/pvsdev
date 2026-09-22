import styles from '@/components/site/Section.module.css';

interface SectionProps {
  id: string;
  index: string;
  label: string;
  title: string;
  description?: string;
  children: React.ReactNode;
}

export default function Section({ id, index, label, title, description, children }: SectionProps) {
  return (
    <section id={id} className={styles.section} aria-labelledby={`${id}-title`}>
      <div className={styles.inner}>
        <div className={styles.head}>
          <p className={styles.label}>
            {index} <span aria-hidden="true">/</span> {label}
          </p>
          {description ? <p className={styles.lead}>{description}</p> : null}
        </div>
        <h2 id={`${id}-title`} className={styles.title}>
          {title}
        </h2>
        <div className={styles.content}>{children}</div>
      </div>
    </section>
  );
}
