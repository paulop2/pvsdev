import BoxesScene from '@/components/BoxesScene';

export const metadata = { title: 'Boxes' };

export default function BoxesPage() {
  return (
    <div>
      <h1>Click on me - Hover me :)</h1>
      <BoxesScene />
    </div>
  );
}
