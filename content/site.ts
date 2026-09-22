export interface SiteLink {
  label: string;
  href: string;
}

export interface NavItem {
  id: string;
  label: string;
  href: string;
}

export interface Cta {
  id: string;
  label: string;
  href: string;
  variant: 'primary' | 'ghost' | 'accent';
}

export interface ServiceItem {
  id: string;
  index: string;
  title: string;
  description: string;
  tags: string[];
  learning?: boolean;
}

export interface ProjectItem {
  id: string;
  name: string;
  summary: string | null;
  role: string | null;
  link: SiteLink | null;
  tags: string[];
  note: string | null;
}

export interface EvidenceItem {
  id: string;
  value: string;
  label: string;
}

export interface StackGroup {
  id: string;
  title: string;
  items: string[];
}

export interface WritingItem {
  id: string;
  index: string;
  title: string;
  summary: string;
  type: string;
  href: string;
}

export interface FooterColumn {
  id: string;
  title: string;
  links: SiteLink[];
}

export const identity = {
  name: 'Paulo Vitor Souza',
  firstName: 'Paulo Vitor',
  brand: 'pvsdev',
  role: 'Desenvolvedor fullstack',
  location: 'Campinas / Valinhos, SP',
  workMode: 'Remoto',
  focus: 'Desenvolvimento fullstack com TypeScript',
} as const;

export const siteMeta = {
  title: 'pvsdev — Paulo Vitor Souza',
  description:
    'Portfólio de Paulo Vitor Souza: desenvolvimento fullstack com TypeScript, produtos web e consultoria de IA.',
} as const;

export const marqueeItems: string[] = [
  'Desenvolvimento fullstack',
  'TypeScript',
  'React / Next.js',
  'Cloudflare Workers',
  'Consultoria de IA',
  'Go · IoT · Edge em aprendizado',
  'Campinas / Valinhos · SP',
  'Remoto',
];

export const navItems: NavItem[] = [
  { id: 'nav-projetos', label: 'Projetos', href: '#projetos' },
  { id: 'nav-atuacao', label: 'Atuação', href: '#atuacao' },
  { id: 'nav-stack', label: 'Stack', href: '#stack' },
  { id: 'nav-textos', label: 'Textos', href: '#textos' },
  { id: 'nav-sobre', label: 'Sobre', href: '/posts/about-me/' },
];

export const chatCta: Cta = {
  id: 'cta-chat',
  label: 'Conversar com meu assistente',
  href: '/chat/',
  variant: 'ghost',
};

export const hero = {
  greeting: 'Olá, eu sou',
  headline: ['Desenvolvimento', 'fullstack para', 'produtos web'],
  accentLine: 1,
  kicker: 'TS · REACT / NEXT.JS · CLOUDFLARE WORKERS',
  description:
    'Trabalho com TypeScript no front e no back — de interfaces React/Next.js a APIs em Cloudflare Workers. Também presto consultoria de IA pela Hexeract AI LLC.',
  ctas: [
    { id: 'cta-projetos', label: 'Ver projetos', href: '#projetos', variant: 'primary' },
    chatCta,
  ] as Cta[],
} as const;

export const services: ServiceItem[] = [
  {
    id: 'service-fullstack',
    index: '01',
    title: 'Produtos web fullstack',
    description:
      'Interfaces e APIs em TypeScript, de telas em React/Next.js a serviços e integrações em Cloudflare Workers.',
    tags: ['TypeScript', 'React / Next.js', 'Node.js'],
  },
  {
    id: 'service-ia',
    index: '02',
    title: 'Consultoria de IA',
    description:
      'Apoio a produtos e fluxos com IA pela Hexeract AI LLC, do desenho da integração à entrega.',
    tags: ['IA', 'Integrações'],
  },
  {
    id: 'service-aprendizado',
    index: '03',
    title: 'Go, IoT e Edge',
    description:
      'Interesse ativo em computação na borda e dispositivos conectados, em estudo e experimentação.',
    tags: ['Go', 'IoT', 'Edge'],
    learning: true,
  },
];

export const projects: ProjectItem[] = [
  {
    id: 'project-solufil',
    name: 'Solufil',
    summary: null,
    role: null,
    link: null,
    tags: [],
    note: 'Papel, resultados e links ainda não documentados.',
  },
  {
    id: 'project-pvsdev',
    name: 'Este portfólio',
    summary:
      'Site estático em Next.js com export para Cloudflare Pages, assistente de IA em Worker separado e experimentos com Three.js.',
    role: 'Desenvolvimento fullstack',
    link: { label: 'Ver o chat', href: '/chat/' },
    tags: ['Next.js', 'TypeScript', 'Cloudflare Workers', 'Three.js'],
    note: null,
  },
];

export const evidence: EvidenceItem[] = [
  { id: 'ev-next', value: 'Next.js 15', label: 'App Router com export estático' },
  { id: 'ev-workers', value: 'Worker de IA', label: 'API do chat em Worker separado' },
  { id: 'ev-ts', value: 'TypeScript', label: 'Tipagem estrita em todo o app' },
  { id: 'ev-tests', value: 'Vitest', label: 'Testes no parser de streaming do chat' },
];

export const stackGroups: StackGroup[] = [
  {
    id: 'stack-practical',
    title: 'Uso no dia a dia',
    items: ['TypeScript', 'Node.js', 'React / Next.js', 'Cloudflare Workers', 'Python', 'Docker'],
  },
  {
    id: 'stack-learning',
    title: 'Em aprendizado',
    items: ['Go', 'IoT', 'Edge'],
  },
];

export const writing: WritingItem[] = [
  {
    id: 'writing-sobre',
    index: '01',
    title: 'Sobre mim',
    summary: 'Hobbies, leituras e um pouco de fora do código.',
    type: 'Sobre',
    href: '/posts/about-me/',
  },
  {
    id: 'writing-rants',
    index: '02',
    title: 'Rants',
    summary: 'Reflexões soltas sobre seguir em frente.',
    type: 'Reflexão',
    href: '/posts/rants/',
  },
  {
    id: 'writing-testes',
    index: '03',
    title: 'Testes',
    summary: 'Página de experimentos com Three.js e outras tecnologias.',
    type: 'Experimento',
    href: '/posts/first-post/',
  },
  {
    id: 'writing-art',
    index: '04',
    title: 'Arte em ASCII',
    summary: 'Um retrato desenhado em caracteres.',
    type: 'Arte',
    href: '/posts/art/',
  },
  {
    id: 'writing-boxes',
    index: '05',
    title: 'Boxes',
    summary: 'Cubos interativos em uma cena 3D no navegador.',
    type: 'Experimento',
    href: '/three/boxes/',
  },
];

export const footer = {
  tagline: 'Desenvolvedor fullstack com TypeScript. Consultoria de IA pela Hexeract AI LLC.',
  columns: [
    {
      id: 'footer-pages',
      title: 'Navegação',
      links: [
        { label: 'Projetos', href: '#projetos' },
        { label: 'Atuação', href: '#atuacao' },
        { label: 'Stack', href: '#stack' },
        { label: 'Textos', href: '#textos' },
        { label: 'Sobre', href: '/posts/about-me/' },
      ],
    },
    {
      id: 'footer-actions',
      title: 'Ações',
      links: [
        { label: 'Conversar com meu assistente', href: '/chat/' },
        { label: 'Voltar ao topo', href: '#top' },
      ],
    },
  ] as FooterColumn[],
  link: {
    label: 'Quero me tornar uma pessoa gentil',
    href: 'https://www.youtube.com/watch?v=pVpMWi-x1GY',
  } as SiteLink,
} as const;
