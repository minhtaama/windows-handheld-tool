cbuffer PanelConfig : register(b0) {
    float panelRatio;
    float3 padding;
};

struct VS_OUTPUT {
    float4 Pos : SV_POSITION;
    float2 UV  : TEXCOORD0;
};

VS_OUTPUT VSMain(uint id : SV_VertexID) {
    VS_OUTPUT output;
    float leftNDC = 1.0f - (2.0f * panelRatio);
    float x = (id == 1 || id == 3) ? 1.0f : leftNDC;
    float y = (id == 0 || id == 1) ? 1.0f : -1.0f;

    float leftU = 1.0f - panelRatio;
    float u = (id == 1 || id == 3) ? 1.0f : leftU;
    float v = (id == 0 || id == 1) ? 0.0f : 1.0f;

    output.Pos = float4(x, y, 0.0f, 1.0f);
    output.UV = float2(u, v);
    return output;
}

Texture2D overlayTexture : register(t0);
SamplerState linearSampler : register(s0);

float4 PSMain(VS_OUTPUT input) : SV_TARGET {
    return overlayTexture.Sample(linearSampler, input.UV);
}
