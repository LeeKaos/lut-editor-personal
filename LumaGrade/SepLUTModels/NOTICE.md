SepLUT model attribution

This app bundles a Core ML conversion of the SepLUT FiveK-sRGB checkpoint:
https://github.com/ImCharlesY/SepLUT

Source revision: 49d8bc3f42c5dfc09140786d0da1e47e3adb0619
Checkpoint: pretrained/SepLUT-FiveK-sRGB-M8#3D17#1D17.pth
Paper: SepLUT: Separable Image-adaptive Lookup Tables for Real-time Image Enhancement, ECCV 2022.

SepLUT source and model are distributed under the Apache License 2.0. The
license text is included beside this notice. The model performs its CNN pass
locally; generated LUTs are applied with Core Image.
