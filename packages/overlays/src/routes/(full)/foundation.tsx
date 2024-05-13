import { createFileRoute } from '@tanstack/react-router';

export const Route = createFileRoute('/(full)/foundation')({
  component: Foundation,
});

function Foundation() {
  return (
    <div className="w-canvas h-canvas relative flex">
      <div className="bg-shark-950 flex h-10 flex-auto grow items-center self-end shadow-[inset_0_2px_0_#1a1f22]"></div>
      <div className="flex">
        <div className="h-canvas bg-shark-950 w-3 shadow-[inset_2px_0_0_#1a1f22]"></div>
        <div className="h-canvas bg-shark-900 w-[74px] shadow-[inset_2px_0_0_#262d32]"></div>
      </div>
    </div>
  );
}
