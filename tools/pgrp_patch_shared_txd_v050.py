from pathlib import Path
import sys
root=Path(sys.argv[1])
view=root/"PgrpRealModelViewerActivity.java"
renderer=root/"PgrpTexturedModelView.java"
s=view.read_text()

def replace(old,new):
    global s
    if old not in s:
        raise RuntimeError("Cannot patch v0.4.9 viewer, missing: "+old[:140])
    s=s.replace(old,new,1)

replace("REAL GTA DFF/TXD PREVIEW  ·  v0.4.9",
        "REAL GTA DFF/TXD PREVIEW  ·  v0.5.0")
replace(
    "GtaWorldModelLoader.ModelData loaded=GtaWorldModelLoader.load(img,new GtaMapPlacementIndexV47.ModelDef(1,model,selectedTxd));",
    """GtaWorldModelLoader.ModelData original=GtaWorldModelLoader.load(img,new GtaMapPlacementIndexV47.ModelDef(1,model,selectedTxd));
            GtaWorldModelLoader.ModelData enriched=original;
            String sharedDetails="No shared textures needed";
            if(!original.missingMaterialTextures.isEmpty()){
                String rootFolder=getSharedPreferences("pgrp_gta_local_assets",MODE_PRIVATE).getString("gta_tree","");
                if(rootFolder.isEmpty()){
                    sharedDetails="Shared vehicle textures not checked: select your GTA root folder on PGRP main screen";
                }else{
                    try{
                        GtaSharedVehicleTxd.Outcome extra=GtaSharedVehicleTxd.merge(
                            this,Uri.parse(rootFolder),original);
                        enriched=extra.model;
                        sharedDetails=extra.detail;
                    }catch(Exception e){
                        sharedDetails="Shared vehicle.txd lookup: "+e.getClass().getSimpleName()+": "+e.getMessage();
                    }
                }
            }
            final GtaWorldModelLoader.ModelData loaded=enriched;
            final String sharedInfo=sharedDetails;"""
)
replace(
    'lookupDetails+(loaded.missingMaterialTextures.isEmpty()',
    'lookupDetails+"\\n"+sharedInfo+"\\nMaterials: "+loaded.materials.materialTextureNames+(loaded.missingMaterialTextures.isEmpty()'
)
if "GtaSharedVehicleTxd.merge" not in s:
    raise RuntimeError("Shared lookup not added")
view.write_text(s)

r=renderer.read_text()
old='int[] white=new int[]{0xffffffff};gpuTextures.put("",upload(1,1,white));'
new='// Diagnostic: bright magenta checkerboard means unresolved/unsupported diffuse material.\n            int[] missing={0xffff00ff,0xff111111,0xff111111,0xffff00ff};gpuTextures.put("",upload(2,2,missing));'
if old not in r:raise RuntimeError("Missing GL fallback marker")
r=r.replace(old,new,1)
renderer.write_text(r)
print("PGRP shared vehicle TXD fallback + material diagnostics patched successfully")
