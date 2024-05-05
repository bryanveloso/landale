import { AnimatePresence, type Variants, motion } from 'framer-motion';
import dynamic from 'next/dynamic';
import { type ComponentType, type FC, useEffect, useState } from 'react';

type ComponentsMap = {
  [key: string]: () => ComponentType;
};

const LabComponent = dynamic(
  async () => (await import('./checkpoints/lab')).Checkpoint
);

const RivalOneComponent = dynamic(
  async () => (await import('./checkpoints/rival-one')).Checkpoint
);

const FirstTrainerComponent = dynamic(
  async () => (await import('./checkpoints/first-trainer')).Checkpoint
);

const Loading = () => {
  return <div>Loading Checkpoint Data...</div>;
};

const componentsMap: ComponentsMap = {
  LAB: () => LabComponent,
  RIVAL1: () => RivalOneComponent,
  FIRSTTRAINER: () => FirstTrainerComponent,

  // Default component.
  DEFAULT: () => Loading,
};

const container: Variants = {
  hidden: { opacity: 0, y: 12 },
  visible: { opacity: 1, y: 0 },
  exit: { opacity: 0, y: -4 },
};

export const Checkpoint: FC<{ id: number; name: string }> = ({ id, name }) => {
  // eslint-disable-next-line react/display-name
  const [Component, setComponent] = useState<ComponentType>(() => Loading);

  useEffect(() => {
    const SelectedComponent = componentsMap[name] || componentsMap['DEFAULT'];
    setComponent(SelectedComponent);
  }, [name]);

  return (
    <AnimatePresence mode="wait">
      <motion.div
        key={name}
        initial={{ opacity: 0, x: -4 }}
        animate={{ opacity: 1, x: 0 }}
        exit={{ opacity: 0, x: 4 }}
        transition={{ staggerChildren: 0.5 }}
        className="flex basis-full items-center gap-12"
      >
        <Component />
      </motion.div>
    </AnimatePresence>
  );
};
