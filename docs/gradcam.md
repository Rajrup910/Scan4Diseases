# Grad-CAM

**Implementation:** [`ml/explainability/gradcam.py`](../ml/explainability/gradcam.py) (training-side),
[`backend/app/services/gradcam.py`](../backend/app/services/gradcam.py) (serving-side).
Written from first principles rather than imported, because the report has to explain it
anyway and it is about 120 lines.

## What it answers

> Which regions of the image contributed most to the score the model gave the predicted class?

Note what that sentence does **not** say. It says nothing about whether those regions are
medically relevant, and nothing about whether the model's reasoning resembles a
dermatologist's. Keeping that distinction is the difference between a defensible
explainability section and an overclaim.

## Method

Selvaraju et al., ICCV 2017. For predicted class `c` and the feature maps `A^k` of a late
convolutional layer:

```
1.  forward pass, capture A^k                    (hook on the target layer)
2.  pick class c                                 (argmax, or a class chosen explicitly)
3.  backward from the score y^c, capture ∂y^c/∂A^k
4.  importance weight per channel:
        a^c_k = (1/Z) ΣᵢΣⱼ ∂y^c / ∂A^k_ij       (spatial average of the gradient)
5.  weighted sum over channels:  Σₖ a^c_k · A^k
6.  ReLU                                         (keep evidence FOR the class only)
7.  normalise to [0, 1]
8.  bilinear upsample to the input size, overlay
```

Step 6 is not cosmetic. Without ReLU the map mixes evidence for and against the class, and
the result is not interpretable as "where the model saw this class".

## Target layer

| Architecture | Layer | Output resolution at 224×224 |
|---|---|---|
| ResNet-50 | `model.layer4[-1]` | 7 × 7 |
| EfficientNet-B0 | `model.features[-1]` | 7 × 7 |

The last convolutional block is the standard choice: deep enough to carry class-level
semantics, shallow enough to retain spatial structure. Earlier layers give sharper maps of
edges and textures that are not class-specific; the classifier head has no spatial structure
left at all.

## Two implementation details worth knowing

**The input must require gradients.** A model loaded purely for inference has every
parameter frozen. If the input tensor also does not require grad, PyTorch builds no autograd
graph, the backward pass silently produces nothing, and you get a confusing "no gradients
captured" error — or worse, a plausible-looking map from stale state. Both implementations
call `input_tensor.requires_grad_(True)`.

**Hooks must be removed.** The API server reuses one model across every request. A forward
hook left attached accumulates captured activations and leaks memory slowly enough that it
only shows up under load. Both implementations are context managers, and
`test_gradcam_hooks_are_removed` asserts the hook count returns to its starting value.

## Validation — the part most projects skip

Section 18 of the master specification is explicit: producing a heatmap and calling it
explainability is not enough.

[`ml/explainability/generate_gradcam.py`](../ml/explainability/generate_gradcam.py) samples
images per class from the test split, writes the overlays, and computes:

| Statistic | Meaning |
|---|---|
| `border_mass_fraction` | share of activation in the outer 15% frame |
| `peak_offset_from_centre` | distance of the hottest point from centre, 1.0 = corner |
| `activation_above_half` | how diffuse the map is |
| `is_degenerate` | the map is entirely zero |

Lesions in HAM10000 are roughly centred, so **border mass above 50% is flagged**. That
pattern suggests the model is responding to vignetting, the dermatoscope's circular frame,
hairs, rulers, or ink marks rather than to the lesion.

If many images are flagged, investigate before claiming explainability:

- dataset bias (do the malignant images come from a different scanner?)
- preprocessing (is the centre crop cutting the lesion?)
- artefacts (rulers and ink correlate with malignancy in some archives, because a clinician
  bothered to measure them)
- leakage

Filenames encode the outcome so the failures are easy to find:

```
mel_ISIC_0027419_pred-nv_0.42_ERR.png
```

Sort by `ERR` and read those first. A confident wrong prediction with a convincing heatmap
is the single most informative image in the whole set.

## Reading a heatmap honestly

| Observation | Reasonable reading |
|---|---|
| Hot on the lesion, correct prediction | consistent with the model using lesion features |
| Hot on the lesion, wrong prediction | it looked in the right place and still misread it |
| Hot on the border, correct prediction | **warning** — possibly right for the wrong reason |
| Diffuse over everything | weak or no localised evidence |
| Entirely zero | no positive evidence for that class at that layer |

The third row is the one to take seriously. A model that is accidentally right is not a
model you can deploy.

## Limitations to state in the report

1. **It shows influence, not correctness.** Grad-CAM cannot show that the model used
   medically valid features, and must not be presented as proof that it did.
2. **The resolution is 7×7.** Everything finer in the overlay is bilinear interpolation. The
   apparent precision is an artefact of upsampling.
3. **It explains one class at a time.** The map for the runner-up class can look equally
   convincing — worth generating for a slide, because it makes the point vividly.
4. **It is not a segmentation.** Hot regions are not lesion boundaries.
5. **Grad-CAM has known failure modes** with multiple instances of a class and with
   gradient saturation.

## Using it

```bash
.venv/Scripts/python.exe -m ml.explainability.generate_gradcam --checkpoint ml/checkpoints/efficientnet_b0_best.pt --per-class 8
```

```bash
.venv/Scripts/python.exe -m ml.explainability.generate_gradcam --checkpoint ml/checkpoints/efficientnet_b0_best.pt --only-errors
```

Outputs land in `ml/results/<arch>/gradcam/`: the overlays, `gradcam_stats.csv`, and
`gradcam_report.md`.

At serving time the overlay is generated inside the same request as the prediction and
returned as `gradcam_url`, alongside a deliberately geometric `gradcam_focus` string
("concentrated on the central region of the image"). It stays geometric on purpose — the
model has no concept of lesion borders or pigment networks, and describing the heatmap in
clinical language would be exactly the overclaim the safety layer exists to prevent.
