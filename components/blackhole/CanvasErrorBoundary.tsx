'use client';

import { Component, type ReactNode } from 'react';

interface CanvasErrorBoundaryProps {
  children: ReactNode;
  onError?: () => void;
}

interface CanvasErrorBoundaryState {
  failed: boolean;
}

export default class CanvasErrorBoundary extends Component<
  CanvasErrorBoundaryProps,
  CanvasErrorBoundaryState
> {
  state: CanvasErrorBoundaryState = { failed: false };

  static getDerivedStateFromError(): CanvasErrorBoundaryState {
    return { failed: true };
  }

  componentDidCatch(): void {
    this.props.onError?.();
  }

  render(): ReactNode {
    if (this.state.failed) {
      return null;
    }
    return this.props.children;
  }
}
