import { motion } from 'framer-motion';
import { FC } from 'react';

export const Initializer: FC = () => {
  return (
    <motion.div className="flex items-center">
      <motion.span
        className="font-mono text-xl font-bold uppercase tracking-wide"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
      >
        <span className="text-main-avayellow">&gt; </span>
        <motion.span
          initial={{ opacity: 0.5 }}
          animate={{ opacity: 1 }}
          transition={{
            repeat: Infinity,
            repeatType: 'mirror',
            duration: 1.0,
          }}
        >
          Initializing Ironmon Connect...
        </motion.span>
      </motion.span>
    </motion.div>
  );
};
