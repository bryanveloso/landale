import { createFileRoute } from '@tanstack/react-router';

export const Route = createFileRoute('/(full)/foundation')({
  component: Foundation,
});

function Foundation() {
  return (
    <div className="relative flex h-canvas w-canvas">
      <div className="flex h-10 flex-auto grow items-center self-end bg-shark-950 shadow-[inset_0_2px_0_#1a1f22]"></div>
      <div className="flex">
        <div className="h-canvas w-3 bg-shark-950 shadow-[inset_2px_0_0_#1a1f22]"></div>
        <div className="h-canvas w-[74px] bg-shark-900 shadow-[inset_2px_0_0_#262d32]"></div>
      </div>
    </div>
  );
}
