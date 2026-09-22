import Link from 'next/link';
import { evidence, projects, sectionMeta } from '@/content/site';
import Section from '@/components/site/Section';
import styles from '@/components/site/Projects.module.css';

export default function Projects() {
  return (
    <Section id="projetos" {...sectionMeta.projetos}>
      <ul className={styles.list}>
        {projects.map((project) => {
          const isExternal = project.link ? /^https?:\/\//.test(project.link.href) : false;
          return (
            <li key={project.id} className={styles.card}>
              <div className={styles.top}>
                <h3 className={styles.name}>{project.name}</h3>
                {project.role ? <span className={styles.role}>{project.role}</span> : null}
              </div>

              {project.summary ? <p className={styles.summary}>{project.summary}</p> : null}
              {project.note ? <p className={styles.note}>{project.note}</p> : null}

              {project.tags.length > 0 ? (
                <ul className={styles.tags}>
                  {project.tags.map((tag) => (
                    <li key={tag} className={styles.tag}>
                      {tag}
                    </li>
                  ))}
                </ul>
              ) : null}

              {project.link ? (
                isExternal ? (
                  <a
                    className={styles.link}
                    href={project.link.href}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {project.link.label} <span aria-hidden="true">→</span>
                  </a>
                ) : (
                  <Link className={styles.link} href={project.link.href}>
                    {project.link.label} <span aria-hidden="true">→</span>
                  </Link>
                )
              ) : null}
            </li>
          );
        })}
      </ul>

      <div className={styles.evidence}>
        <p className={styles.evidenceLabel}>Evidências</p>
        <ul className={styles.evidenceGrid}>
          {evidence.map((item) => (
            <li key={item.id} className={styles.evidenceCell}>
              <span className={styles.evidenceValue}>{item.value}</span>
              <span className={styles.evidenceText}>{item.label}</span>
            </li>
          ))}
        </ul>
      </div>
    </Section>
  );
}
