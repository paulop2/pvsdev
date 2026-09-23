import { describe, expect, it } from 'vitest';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import ReactMarkdown from 'react-markdown';
import { markdownRehypePlugins, markdownRemarkPlugins } from './markdown';

function renderMarkdown(source: string): string {
  return renderToStaticMarkup(
    createElement(
      ReactMarkdown,
      {
        remarkPlugins: markdownRemarkPlugins,
        rehypePlugins: markdownRehypePlugins,
      },
      source,
    ),
  );
}

describe('markdown do chat', () => {
  it('renderiza tabelas GFM', () => {
    const html = renderMarkdown(
      '| Nome | Stack |\n| --- | --- |\n| Paulo | TypeScript |',
    );
    expect(html).toContain('<table>');
    expect(html).toContain('<th>Nome</th>');
    expect(html).toContain('<td>Paulo</td>');
  });

  it('renderiza listas de tarefas e strikethrough GFM', () => {
    const html = renderMarkdown('- [x] feito\n- [ ] pendente\n\n~~antigo~~');
    expect(html).toContain('type="checkbox"');
    expect(html).toContain('<del>antigo</del>');
  });

  it('realca blocos de codigo com linguagem', () => {
    const html = renderMarkdown('```ts\nconst total: number = 1;\n```');
    expect(html).toContain('class="hljs');
    expect(html).toContain('hljs-keyword');
    expect(html).toContain('language-ts');
  });

  it('renderiza listas', () => {
    const html = renderMarkdown('- um\n- dois\n\n1. primeiro\n2. segundo');
    expect(html).toContain('<ul>');
    expect(html).toContain('<li>um</li>');
    expect(html).toContain('<ol>');
  });

  it('renderiza links', () => {
    const html = renderMarkdown('[docs](https://example.com)');
    expect(html).toContain('<a href="https://example.com">docs</a>');
  });

  it('neutraliza URLs perigosas nos links', () => {
    const html = renderMarkdown('[x](javascript:alert(1))');
    expect(html).not.toContain('javascript:');
    expect(html).not.toContain('href="javascript');
  });

  it('nao renderiza HTML cru', () => {
    const html = renderMarkdown(
      'Antes <img src=x onerror=alert(1)> depois\n\n<script>alert(2)</script>',
    );
    expect(html).not.toContain('<img');
    expect(html).not.toContain('<script');
    expect(html).toContain('&lt;img');
    expect(html).toContain('&lt;script&gt;');
  });
});
