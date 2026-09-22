'use client';

import { useEffect, useMemo, useRef } from 'react';
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import * as THREE from 'three';
import { fragmentShader, vertexShader } from '@/components/blackhole/shaders';

export interface BlackHoleCanvasProps {
  intensity?: number;
  quality?: number;
  paused?: boolean;
  pointerEnabled?: boolean;
  onReady?: () => void;
  onContextLost?: () => void;
}

function BlackHolePlane({
  intensity = 1,
  quality = 1,
  paused = false,
  pointerEnabled = true,
  onReady,
  onContextLost,
}: BlackHoleCanvasProps) {
  const materialRef = useRef<THREE.ShaderMaterial | null>(null);
  const gl = useThree((state) => state.gl);
  const size = useThree((state) => state.size);
  const viewport = useThree((state) => state.viewport);
  const target = useRef(new THREE.Vector2(0, 0));
  const damped = useRef(new THREE.Vector2(0, 0));
  const readyRef = useRef(false);

  const uniforms = useMemo(
    () => ({
      uTime: { value: 0 },
      uResolution: { value: new THREE.Vector2(1, 1) },
      uIntensity: { value: intensity },
      uQuality: { value: quality },
      uMouse: { value: new THREE.Vector2(0, 0) },
    }),
    [],
  );

  useEffect(() => {
    uniforms.uIntensity.value = intensity;
  }, [uniforms, intensity]);

  useEffect(() => {
    uniforms.uQuality.value = quality;
  }, [uniforms, quality]);

  useEffect(() => {
    uniforms.uResolution.value.set(size.width, size.height);
  }, [uniforms, size.width, size.height]);

  useEffect(() => {
    if (!pointerEnabled) {
      return;
    }
    const element = gl.domElement;
    const onMove = (event: PointerEvent) => {
      if (event.pointerType !== 'mouse') {
        return;
      }
      const rect = element.getBoundingClientRect();
      if (rect.width === 0 || rect.height === 0) {
        return;
      }
      target.current.set(
        ((event.clientX - rect.left) / rect.width) * 2 - 1,
        -(((event.clientY - rect.top) / rect.height) * 2 - 1),
      );
    };
    element.addEventListener('pointermove', onMove);
    return () => element.removeEventListener('pointermove', onMove);
  }, [gl, pointerEnabled]);

  useEffect(() => {
    const element = gl.domElement;
    const onLost = (event: Event) => {
      event.preventDefault();
      onContextLost?.();
    };
    element.addEventListener('webglcontextlost', onLost);
    return () => element.removeEventListener('webglcontextlost', onLost);
  }, [gl, onContextLost]);

  useFrame((_, delta) => {
    const material = materialRef.current;
    if (!material) {
      return;
    }
    if (!paused) {
      material.uniforms.uTime.value += Math.min(delta, 0.05);
    }
    damped.current.lerp(target.current, 0.05);
    material.uniforms.uMouse.value.copy(damped.current);
    if (!readyRef.current) {
      readyRef.current = true;
      onReady?.();
    }
  });

  return (
    <mesh scale={[viewport.width, viewport.height, 1]}>
      <planeGeometry args={[1, 1]} />
      <shaderMaterial
        ref={materialRef}
        vertexShader={vertexShader}
        fragmentShader={fragmentShader}
        uniforms={uniforms}
        depthTest={false}
        depthWrite={false}
      />
    </mesh>
  );
}

export default function BlackHoleCanvas(props: BlackHoleCanvasProps) {
  return (
    <Canvas
      orthographic
      camera={{ position: [0, 0, 1], zoom: 1 }}
      dpr={[1, 1.5]}
      frameloop={props.paused ? 'never' : 'always'}
      gl={{ antialias: true, alpha: true, powerPreference: 'high-performance' }}
      onCreated={({ gl }) => gl.setClearAlpha(0)}
      style={{ width: '100%', height: '100%' }}
    >
      <BlackHolePlane {...props} />
    </Canvas>
  );
}
