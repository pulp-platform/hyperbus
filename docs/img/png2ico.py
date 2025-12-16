from PIL import Image

img = Image.open("CHIPS_Symbolo_RGB_Colore.png")

img.save("CHIPS_Symbolo_RGB_Colore.ico", format="ICO", sizes=[(16,16), (32,32), (48,48), (64,64), (128,128), (256,256)])
