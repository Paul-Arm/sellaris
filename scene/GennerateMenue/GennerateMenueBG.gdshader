// Observatory backdrop: seeded dust, distant stars and a sunlit planetary limb.
shader_type canvas_item;
uniform vec4 background_color : source_color = vec4(0.005, 0.008, 0.02, 1.0);
uniform float motion_speed = 0.05;
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
 vec2 i = floor(p); vec2 f = fract(p); vec2 u = f*f*(3.0-2.0*f);
 return mix(mix(hash21(i), hash21(i+vec2(1,0)),u.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1)),u.x),u.y);
}
float fbm(vec2 p) {
 float n=0.0; float a=0.5;
 for(int i=0;i<5;i++){n+=a*noise(p);p=mat2(vec2(1.6,1.2),vec2(-1.2,1.6))*p+7.1;a*=0.5;}
 return n;
}
void fragment() {
 vec2 p=UV; p.x/=SCREEN_PIXEL_SIZE.x/SCREEN_PIXEL_SIZE.y;
 float aspect=SCREEN_PIXEL_SIZE.y/SCREEN_PIXEL_SIZE.x;
 vec3 col=background_color.rgb;
 vec2 drift=vec2(TIME*motion_speed*0.025,0.0);
 float dust=fbm(p*2.4+drift);
 col+=vec3(0.025,0.10,0.13)*pow(dust,3.0);
 for(int i=0;i<2;i++){
  float scale=180.0+float(i)*110.0;
  vec2 cell=floor(p*scale); vec2 f=fract(p*scale)-0.5;
  float h=hash21(cell+float(i)*17.0);
  float point=exp(-dot(f,f)*(300.0+150.0*float(i)))*step(0.985,h);
  col+=mix(vec3(0.5,0.73,0.85),vec3(0.95,0.83,0.59),h)*point*(0.5+0.5*h);
 }
 vec2 q=(p-vec2(aspect*0.85,0.59))/0.47;
 float r=length(q);
 float aa=fwidth(r)*1.5;
 vec3 light=normalize(vec3(-0.65,-0.45,0.62));
 float halo=exp(-abs(r-1.0)*44.0)*(0.35+0.65*clamp(-q.x-q.y,0.0,1.0));
 col+=vec3(0.16,0.66,0.79)*halo*0.6;
 if(r<1.0){
  vec3 n=vec3(q,sqrt(max(0.0,1.0-dot(q,q))));
  float land=fbm(n.xy*4.0+vec2(n.z*2.0)+drift*0.04);
  vec3 surface=mix(vec3(0.014,0.055,0.095),vec3(0.18,0.23,0.16),smoothstep(0.47,0.52,land));
  float clouds=smoothstep(0.59,0.75,fbm(n.xy*7.0+vec2(n.z)+4.0));
  surface=mix(surface,vec3(0.65,0.78,0.79),clouds*0.65);
  float day=max(dot(n,light),0.0);
  vec3 planet=surface*(0.035+day*1.8);
  planet+=vec3(0.12,0.54,0.75)*pow(1.0-n.z,4.0)*day;
  col=mix(planet,col,smoothstep(1.0-aa,1.0,r));
 }
 // Dark left gutter keeps navigation readable, including on ultrawide displays.
 col*=mix(0.45,1.0,smoothstep(0.15,0.8,UV.x));
 col*=1.0-0.22*length(UV-0.5);
 COLOR=vec4(col,1.0);
}
