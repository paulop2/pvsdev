import { sectionMeta, stackGroups } from '@/content/site';
import Section from '@/components/site/Section';
import styles from '@/components/site/Stack.module.css';

export default function Stack() {
  return (
    <Section id="stack" {...sectionMeta.stack}>
      <div className={styles.groups}>
        {stackGroups.map((group) => (
          <div key={group.id} className={styles.group}>
            <h3 className={styles.groupTitle}>{group.title}</h3>
            <ul className={styles.pills}>
              {group.items.map((item) => (
                <li key={item} className={styles.pill}>
                  {item}
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </Section>
  );
}
