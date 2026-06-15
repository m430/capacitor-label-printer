import { nodeResolve } from '@rollup/plugin-node-resolve';
import typescript from '@rollup/plugin-typescript';

export default {
  input: 'src/index.ts',
  output: [
    { file: 'dist/plugin.js', format: 'es', sourcemap: true, inlineDynamicImports: true },
    { file: 'dist/plugin.cjs.js', format: 'cjs', sourcemap: true, exports: 'named', inlineDynamicImports: true }
  ],
  external: ['@capacitor/core'],
  plugins: [
    nodeResolve(),
    typescript({
      tsconfig: './tsconfig.json',
      compilerOptions: {
        declaration: false,
        declarationMap: false,
        outDir: './dist'
      }
    })
  ]
};
