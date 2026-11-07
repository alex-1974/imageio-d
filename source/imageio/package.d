/**
 * Format-neutral image I/O contracts.
 *
 * The package describes decoded image regions without depending on raster-d
 * or imagery-d. Format readers and transport-backed readers are added behind
 * this contract as they are admitted by the research gates.
 */
module imageio;

public import imageio.region;
public import imageio.tiff;
