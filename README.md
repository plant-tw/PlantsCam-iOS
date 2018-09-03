# PlantsCam-iOS

## Prepare 1: Dependency

Clone this project, and then run:
```
git submodule init
git submodule update
```

## Prepare 2: ML Inference

Train model by yourself, or download our model (`labels.txt` and `Plant.mlmodel` from [here](https://drive.google.com/open?id=1ALrku-CWORa7vuyH65FqMhxrZX4lD6WK)). Put them in the `ARSampleApp` folder.

## Data Collecting

Use this app to collect image, with related sensor information stored in `UserComment` field of Exif data.

Turn on "Camera Mode" in iOS Settings. Take out images with iTunes File Sharing.


