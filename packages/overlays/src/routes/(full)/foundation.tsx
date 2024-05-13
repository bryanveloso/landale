import { createFileRoute } from '@tanstack/react-router';

export const Route = createFileRoute('/(full)/foundation')({
  component: Foundation,
});

function Foundation() {
  return (
    <div className="w-canvas h-canvas relative">
      <div className="absolute right-0 -z-10 flex">
        <div className="h-canvas bg-shark-950 w-3 shadow-[inset_2px_0_0_#1a1f22]"></div>
        <div className="h-canvas bg-shark-900 w-[74px] shadow-[inset_2px_0_0_#262d32]"></div>
      </div>
    </div>
  );
}
