export const vertexShader = `
  varying vec2 vUv;

  void main() {
    vUv = uv;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

export const fragmentShader = `
  varying vec2 vUv;

  uniform float uTime;
  uniform vec2 uResolution;
  uniform float uIntensity;
  uniform float uQuality;
  uniform vec2 uMouse;

  float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
  }

  float starLayer(vec2 uv, float t, float density) {
    vec2 g = floor(uv);
    vec2 f = fract(uv) - 0.5;
    float h = hash(g);
    float present = step(1.0 - density, h);
    float d = length(f);
    float s = (1.0 - smoothstep(0.0, 0.42, d)) * present;
    float tw = 0.6 + 0.4 * sin(t * 1.7 + h * 40.0);
    return s * tw;
  }

  void main() {
    vec2 uv = vUv;
    float aspect = uResolution.x / max(uResolution.y, 1.0);
    vec2 p = (uv - 0.5) * 2.0;
    p.x *= aspect;

    vec2 par = uMouse * 0.06;
    vec2 d = p - par;

    float t = uTime;
    float r = length(d);
    vec2 dir = r > 0.0001 ? d / r : vec2(1.0, 0.0);

    float horizon = 0.30 + 0.004 * sin(t * 0.5);
    float spin = t * 0.12;

    vec3 col = vec3(0.0);

    float bend = 0.05 / (r + 0.22);
    vec2 starUv = (uv + par) * (1.0 + bend) - dir * bend * 0.5;
    float cellBase = mix(90.0, 170.0, uQuality);
    float stars = starLayer(starUv * cellBase, t, 0.05);
    stars += starLayer(starUv * cellBase * 1.7 + 13.0, t * 1.3, 0.03) * 0.7;

    float tilt = 0.36;
    float ca = cos(tilt);
    float sa = sin(tilt);
    vec2 q = vec2(ca * d.x + sa * d.y, -sa * d.x + ca * d.y);
    vec2 diskPos = vec2(q.x, q.y / 0.34);
    float diskR = length(diskPos) * 1.7;
    float diskAngle = atan(diskPos.y, diskPos.x);

    float arms = 0.5 + 0.5 * sin(diskAngle * 2.0 + spin * 6.0 - diskR * 7.0);
    float ring = 1.0 - smoothstep(0.0, 0.62, abs(diskR - 0.95));
    float inner = smoothstep(0.42, 0.7, diskR);
    float disk = ring * inner * (0.45 + 0.55 * arms);

    float doppler = 0.7 + 0.6 * smoothstep(-1.0, 1.0, sin(diskAngle));
    disk *= doppler;

    vec3 diskCol = mix(
      vec3(0.05, 0.25, 0.10),
      vec3(0.29, 0.87, 0.50),
      clamp((diskR - 0.5) / 0.6, 0.0, 1.0)
    );
    diskCol = mix(diskCol, vec3(0.0, 1.0, 0.25), clamp(arms, 0.0, 1.0) * 0.5);
    col += diskCol * disk * uIntensity * 1.1;

    float photon = 1.0 - smoothstep(0.0, 0.012, abs(r - (horizon + 0.045)));
    float topArc = smoothstep(0.2, 0.9, -dir.y);
    float arc = (1.0 - smoothstep(0.0, 0.05, abs(r - (horizon + 0.10)))) * topArc;
    col += vec3(0.0, 1.0, 0.28) * (photon * 0.9 + arc * 0.7) * uIntensity;

    float glow = exp(-(r - horizon) * 6.0) * step(horizon, r);
    col += vec3(0.09, 0.35, 0.16) * glow * 0.6 * uIntensity;

    col += vec3(0.72, 0.95, 0.78) * stars *
      (1.0 - smoothstep(horizon - 0.02, horizon + 0.06, r));

    float shadow = 1.0 - smoothstep(horizon - 0.02, horizon, r);
    col *= (1.0 - shadow);

    float vig = 1.0 - smoothstep(0.35, 1.7, length((uv - 0.5) * vec2(aspect, 1.0) * 2.0));
    col *= mix(0.55, 1.0, vig);
    col += (hash(uv * uResolution + t) - 0.5) * 0.012;

    float lum = max(max(col.r, col.g), col.b);
    float core = 1.0 - smoothstep(horizon, horizon + 0.05, r);
    float alpha = clamp(max(lum * 1.9, core), 0.0, 1.0);
    alpha *= 1.0 - smoothstep(0.72, 1.08, length(p));

    gl_FragColor = vec4(col * alpha, alpha);
  }
`;
