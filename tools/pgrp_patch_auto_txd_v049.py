from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
def change(old,new):
 global s
 assert old in s, ('missing marker',old)
 s=s.replace(old,new,1)
change('REAL GTA DFF/TXD PREVIEW  ·  v0.4.7','REAL GTA DFF/TXD PREVIEW  ·  v0.4.9')
change('txdText.setText("exh_lr_bl2");txdText.setHint("TXD archive name without .txd")', 'txdText.setText("auto");txdText.setHint("auto = read real TXD from GTA IDE files")')
change('s.append("\\nTip: Enter a DFF and its matching TXD name.");report(s.toString());','s.append("\\nTXD archives: ");int txdCount=0;for(String name:img.directory().keySet())if(name.endsWith(".txd")){if(txdCount<18)s.append(name).append("  ");txdCount++;}s.append("\\nTotal TXD: ").append(txdCount).append("\\nSelect your GTA folder in the main PGRP screen to enable automatic IDE lookup.");report(s.toString());')
change('final String txd=txdText.getText().toString().trim().toLowerCase(Locale.ROOT).replaceAll("\\\\.txd$","");','final String txdInput=txdText.getText().toString().trim().toLowerCase(Locale.ROOT).replaceAll("\\\\.txd$","");')
change('||!txd.matches("[a-z0-9_.$-]{1,64}")','||(!txdInput.isEmpty()&&!txdInput.matches("[a-z0-9_.$-]{1,64}"))')
change('''            GtaWorldModelLoader.ModelData loaded=GtaWorldModelLoader.load(img,new GtaMapPlacementIndex.ModelDef(1,model,txd));''','''            String selectedTxd=txdInput;
            String resolution="Manual TXD dictionary";
            if(selectedTxd.isEmpty()||selectedTxd.equals("auto")||selectedTxd.equals(model)) {
                String savedTree=getSharedPreferences("pgrp_gta_local_assets",MODE_PRIVATE).getString("gta_tree","");
                if(savedTree.isEmpty())throw new IOException("Automatic TXD lookup needs the original GTA folder. Go back to PGRP main screen > GTA data; select folder with data/gta.dat and models/gta3.img. Then try again.");
                GtaIdeTxdResolver.Result found=GtaIdeTxdResolver.resolve(new GtaMapSafSource(this,Uri.parse(savedTree)),model);
                if(found.txd==null)throw new IOException("Model "+model+" was not found in "+found.ideFilesChecked+" IDE files. Enter matching TXD dictionary name manually or select a correct GTA folder.");
                selectedTxd=found.txd;
                resolution="Auto-resolved from "+found.source;
            }
            if(img.find(selectedTxd+".txd")==null)throw new IOException("IDE TXD '"+selectedTxd+".txd' is not in selected gta3.img. It may be stored in another IMG archive. Original model: "+model);
            GtaWorldModelLoader.ModelData loaded=GtaWorldModelLoader.load(img,new GtaMapPlacementIndex.ModelDef(1,model,selectedTxd));
            final String usedTxd=selectedTxd;
            final String lookupDetails=resolution;''')
change('''TextView info=label("REAL GTA MODEL: "+loaded.model+"  |  textures "+loaded.textureByName.size()+"  |  meshes "+loaded.geometry.meshes.size()+"  |  missing "+loaded.missingMaterialTextures.size());''','''TextView info=label("REAL GTA MODEL: "+loaded.model+"  |  TXD "+usedTxd+"  |  textures "+loaded.textureByName.size()+"  |  meshes "+loaded.geometry.meshes.size()+"  |  missing "+loaded.missingMaterialTextures.size()+"\\n"+lookupDetails+(loaded.missingMaterialTextures.isEmpty()?"":"\\nMissing: "+loaded.missingMaterialTextures));''')
assert 'GtaIdeTxdResolver.resolve' in s
p.write_text(s)
print('Patched original PGRP textured viewer to resolve actual TXD names',len(s))
