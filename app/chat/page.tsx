import type { Metadata } from 'next';
import PageShell from '@/components/PageShell';
import Chat from '@/components/Chat';

export const metadata: Metadata = {
  title: 'Chat | PVS DEV',
  description: 'Converse com o assistente de IA do portfolio de Paulo Vitor Souza.',
};

export default function ChatPage() {
  return (
    <PageShell>
      <h1>Chat</h1>
      <Chat />
    </PageShell>
  );
}
