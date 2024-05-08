import React from 'react';
import { createFileRoute } from '@tanstack/react-router';

export const Route = createFileRoute('/')({
  component: Home,
});

function Home() {
  return (
    <div className="p-2">
      <h3>Welcome Home!</h3>
      <p>{React.version}</p>
    </div>
  );
}
