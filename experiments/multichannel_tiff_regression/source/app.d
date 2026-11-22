module app;
import imageio : inspect,planRegion,decodeRegion;
import transport : FileSource;
import std.exception : enforce;
import std.json : JSONValue;
import std.stdio : writeln;

void main(string[] args)
{
    JSONValue[] cases;
    foreach(path;args[1..$])
    {
        auto source=new FileSource(path);
        auto metadata=inspect(source);enforce(metadata.ok,"multichannel inspection");
        foreach(region;[[0,0,19,13],[3,1,9,7],[14,5,5,7],[18,12,1,1]])
        {
            auto plan=planRegion(source,region[0],region[1],region[2],region[3]);enforce(plan.ok);
            auto decoded=decodeRegion(source,region[0],region[1],region[2],region[3]);
            enforce(decoded.ok,"multichannel decode");
            enforce(decoded.sourceInfo.bitsPerSample==metadata.info.bitsPerSample);
            const pixelBytes=metadata.info.samplesPerPixel*(metadata.info.bitsPerSample/8);
            enforce(decoded.region.info.sampleStrideBytes==pixelBytes && decoded.region.info.rowStrideBytes==region[2]*pixelBytes);
            enforce(plan.plan.decodedBytes==decoded.region.data.length && decoded.decodedBytes==decoded.region.data.length);
            enforce(plan.plan.encodedBytes!=0 && decoded.bytesRequested==plan.plan.encodedBytes);
            JSONValue c;
            c["file"]=JSONValue(path);c["region"]=JSONValue(region[]);
            c["bits"]=JSONValue(metadata.info.bitsPerSample);c["components"]=JSONValue(metadata.info.samplesPerPixel);
            c["little"]=JSONValue(metadata.info.header.littleEndian);c["big_tiff"]=JSONValue(metadata.info.header.bigTiff);
            c["bytes"]=JSONValue(decoded.region.data);c["encoded_bytes"]=JSONValue(plan.plan.encodedBytes);
            c["decoded_bytes"]=JSONValue(plan.plan.decodedBytes);cases~=c;
        }
    }
    writeln(JSONValue(cases).toString);
}
