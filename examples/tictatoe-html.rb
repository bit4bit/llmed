
application "tic tac toe", language: 'ruby', output_file: "ticktactoe-html.rb" do
  context "main" do
    <<-LLM
    Implementa el juego de tic tac toe solo usando la libreria estandar.
    LLM
  end
  
  context "para dos jugadores" do
    <<-LLM
    Los jugadores deben poder indicar donde ubicar la ficha.
    Debe dar un ejemplo al usuario de como indicar la posicion.
    LLM
  end

  context "html" do
    "
    La interfaz es en html y el servidor http es embedido,
    al   iniciar el servidor debe mostrar el puerto http.
    "
  end

  context "correciones" do
    "
    esta usando variable @port antes de obtener el valor corregir.
    "
  end
end
